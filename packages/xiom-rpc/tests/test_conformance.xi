// XIOM -- xiom.rpc conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.rpc module (JSON-RPC 2.0 envelope codec
// plus minimal scanner) against its documented contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every builder output is pinned as an exact string. All Str equality goes
// through str_compare: BUG 17 lowers `==` on Str values read from Vec[Str]
// elements to a pointer comparison, so every check below is routed through
// streq instead of `==`. The scanner fixtures are fixed literals, so the
// suite would catch a broken builder or a broken reader.

module rpc_tests
use xiom.io; use xiom.test; use xiom.rpc;
use xiom.string; use xiom.string.compare;

// Pinned builder outputs.
const REQ_ARGS: Str = "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1}";
const REQ_NOP: Str = "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":2}";
const REQ_NEG: Str = "{\"jsonrpc\":\"2.0\",\"method\":\"neg\",\"id\":-7}";
const REQ_BIG: Str = "{\"jsonrpc\":\"2.0\",\"method\":\"big\",\"id\":9007199254740993}";
const NOTIF_ARGS: Str = "{\"jsonrpc\":\"2.0\",\"method\":\"log\",\"params\":{\"level\":\"info\"}}";
const NOTIF_NOP: Str = "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}";
const RESP_ARRAY: Str = "{\"jsonrpc\":\"2.0\",\"result\":[1,2,3],\"id\":3}";
const RESP_UNI: Str = "{\"jsonrpc\":\"2.0\",\"result\":\"München ✓\",\"id\":9}";
const RESP_NULL: Str = "{\"jsonrpc\":\"2.0\",\"result\":null,\"id\":-7}";
const ERR_BASE: Str = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":4}";
const ERR_DATA: Str = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"Parse \\\"error\\\"\",\"data\":{\"detail\":\"x\"}},\"id\":5}";

// Escaping fixtures: input text and the exact escaped output.
const ESC_IN: Str = "a\"b\\c";
const ESC_OUT: Str = "a\\\"b\\\\c";
const CTRL_IN: Str = "a\u{1}b\u{1f}c\u{8}";
const CTRL_OUT: Str = "a\\u0001b\\u001fc\\u0008";

// Mixed escapes used by the round-trip checks: quote, backslash, LF, TAB, CR.
const MIX: Str = "q\"w\\e\nr\tt\ry";
const MIX_ESC: Str = "q\\\"w\\\\e\\nr\\tt\\ry";
const UNI: Str = "München ✓";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok(text) with text equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok { return false; }
  return streq(r.value, want);
}

// True when r is an Err whose message starts with "rpc: ".
fn str_err(r: Result[Str, Str]) -> Bool {
  if r.is_ok { return false; }
  let m = r.error;
  if m.len() < 5 { return false; }
  return streq(string.str_slice(m, 0, 5), "rpc: ");
}

// True when r is Ok(v) with v equal to `want`.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

// True when r is an Err whose message starts with "rpc: ".
fn int_err(r: Result[Int, Str]) -> Bool {
  if r.is_ok { return false; }
  let m = r.error;
  if m.len() < 5 { return false; }
  return streq(string.str_slice(m, 0, 5), "rpc: ");
}

fn t1() -> TestResult {
  var ok = streq(rpc_escape("plain"), "plain");
  if !streq(rpc_escape(""), "") { ok = false; }
  if !streq(rpc_escape("München ✓"), "München ✓") { ok = false; }
  return assert(ok, "escape: plain, empty and UTF-8 text pass through");
}

fn t2() -> TestResult {
  var ok = streq(rpc_escape(ESC_IN), ESC_OUT);
  if !streq(rpc_escape("\""), "\\\"") { ok = false; }
  if !streq(rpc_escape("\\"), "\\\\") { ok = false; }
  return assert(ok, "escape: quote and backslash");
}

fn t3() -> TestResult {
  var ok = streq(rpc_escape("a\nb\tc\rd"), "a\\nb\\tc\\rd");
  return assert(ok, "escape: LF, TAB and CR become backslash-n/t/r");
}

fn t4() -> TestResult {
  var ok = streq(rpc_escape(CTRL_IN), CTRL_OUT);
  return assert(ok, "escape: C0 control bytes become lowercase \\u00xx");
}

fn t5() -> TestResult {
  var ok = streq(rpc_request(1, "subtract", "[42,23]"), REQ_ARGS);
  return assert(ok, "request: exact envelope with params");
}

fn t6() -> TestResult {
  var ok = streq(rpc_request(2, "ping", ""), REQ_NOP);
  if !streq(rpc_request(1, "m", "null"), "{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"params\":null,\"id\":1}") { ok = false; }
  return assert(ok, "request: params omitted only when empty");
}

fn t7() -> TestResult {
  var ok = streq(rpc_request(-7, "neg", ""), REQ_NEG);
  if !streq(rpc_request(9007199254740993, "big", ""), REQ_BIG) { ok = false; }
  return assert(ok, "request: negative and large ids render exactly");
}

fn t8() -> TestResult {
  var ok = streq(rpc_notification("log", "{\"level\":\"info\"}"), NOTIF_ARGS);
  return assert(ok, "notification: exact envelope with params and no id");
}

fn t9() -> TestResult {
  var ok = streq(rpc_notification("ping", ""), NOTIF_NOP);
  return assert(ok, "notification: params omitted when empty");
}

fn t10() -> TestResult {
  var ok = streq(rpc_response(3, "[1,2,3]"), RESP_ARRAY);
  if !streq(rpc_response(9, "\"München ✓\""), RESP_UNI) { ok = false; }
  return assert(ok, "response: exact envelope, unicode result passthrough");
}

fn t11() -> TestResult {
  var ok = streq(rpc_response(-7, ""), RESP_NULL);
  if !streq(rpc_response(0, "0"), "{\"jsonrpc\":\"2.0\",\"result\":0,\"id\":0}") { ok = false; }
  return assert(ok, "response: empty result is null; zero id renders");
}

fn t12() -> TestResult {
  var ok = streq(rpc_error(4, -32601, "Method not found", ""), ERR_BASE);
  return assert(ok, "error: exact envelope without data");
}

fn t13() -> TestResult {
  var ok = streq(rpc_error(5, -32700, "Parse \"error\"", "{\"detail\":\"x\"}"), ERR_DATA);
  return assert(ok, "error: data member included, message escaped");
}

fn t14() -> TestResult {
  var ok = rpc_is_request(REQ_ARGS);
  if !rpc_is_request(rpc_notification("ping", "")) { ok = false; }
  if rpc_is_request(RESP_ARRAY) { ok = false; }
  if rpc_is_request("") { ok = false; }
  if rpc_is_request("jsonrpc only") { ok = false; }
  if !rpc_is_request("jsonrpc ... method") { ok = false; }
  return assert(ok, "is_request: substring probe over built and raw text");
}

fn t15() -> TestResult {
  var ok = rpc_is_error(ERR_BASE);
  if !rpc_is_error("{\"error\":1}") { ok = false; }
  if rpc_is_error(REQ_ARGS) { ok = false; }
  if rpc_is_error("") { ok = false; }
  if !rpc_is_error("errors are only a substring") { ok = false; }
  return assert(ok, "is_error: substring probe over built and raw text");
}

fn t16() -> TestResult {
  var ok = int_ok_is(rpc_id(REQ_ARGS), 1);
  if !int_ok_is(rpc_id(REQ_NEG), -7) { ok = false; }
  if !int_ok_is(rpc_id(REQ_BIG), 9007199254740993) { ok = false; }
  if !int_ok_is(rpc_id("{ \"id\" : 42 }"), 42) { ok = false; }
  if !int_ok_is(rpc_id(rpc_error(5, -32700, "x", "")), 5) { ok = false; }
  return assert(ok, "rpc_id: built envelopes and whitespace raw fixture");
}

fn t17() -> TestResult {
  var ok = int_err(rpc_id(""));
  if !int_err(rpc_id("{}")) { ok = false; }
  if !int_err(rpc_id("{\"id\":null}")) { ok = false; }
  if !int_err(rpc_id("{\"id\":\"7\"}")) { ok = false; }
  if !int_err(rpc_id("{\"id\":12abc}")) { ok = false; }
  if !int_err(rpc_id("{\"id\":}")) { ok = false; }
  if !int_err(rpc_id("{\"id\":-}")) { ok = false; }
  if !int_err(rpc_id("{\"id\":99999999999999999999}")) { ok = false; }
  return assert(ok, "rpc_id: missing/null/quoted/junk/empty/overflow are Err");
}

fn t18() -> TestResult {
  var ok = str_ok_is(rpc_method(REQ_ARGS), "subtract");
  if !str_ok_is(rpc_method("{\"jsonrpc\":\"2.0\",\"method\":\"math.add\"}"), "math.add") { ok = false; }
  if !str_ok_is(rpc_method(rpc_request(1, MIX, "")), MIX) { ok = false; }
  if !str_ok_is(rpc_method(rpc_request(1, UNI, "")), UNI) { ok = false; }
  return assert(ok, "rpc_method: built, raw, escaped and unicode methods");
}

fn t19() -> TestResult {
  var ok = str_err(rpc_method("{}"));
  if !str_err(rpc_method("{\"method\":7}")) { ok = false; }
  if !str_err(rpc_method("{\"method\":\"x}")) { ok = false; }
  if !str_err(rpc_method("")) { ok = false; }
  return assert(ok, "rpc_method: missing/non-string/unterminated are Err");
}

fn t20() -> TestResult {
  var ok = int_ok_is(rpc_error_code(ERR_BASE), -32601);
  if !int_ok_is(rpc_error_code("{\"code\":100}"), 100) { ok = false; }
  if !int_ok_is(rpc_error_code(ERR_DATA), -32700) { ok = false; }
  return assert(ok, "rpc_error_code: built error and raw fixtures");
}

fn t21() -> TestResult {
  var ok = int_err(rpc_error_code(REQ_ARGS));
  if !int_err(rpc_error_code("{\"code\":\"5\"}")) { ok = false; }
  if !int_err(rpc_error_code("{\"code\":12abc}")) { ok = false; }
  if !int_err(rpc_error_code("")) { ok = false; }
  return assert(ok, "rpc_error_code: missing and malformed codes are Err");
}

fn t22() -> TestResult {
  var ok = str_ok_is(rpc_error_message(ERR_BASE), "Method not found");
  if !str_ok_is(rpc_error_message("{\"message\":\"bad request\"}"), "bad request") { ok = false; }
  if !str_ok_is(rpc_error_message(ERR_DATA), "Parse \"error\"") { ok = false; }
  if !str_ok_is(rpc_error_message(rpc_error(1, -1, MIX, "")), MIX) { ok = false; }
  return assert(ok, "rpc_error_message: built, raw and escaped messages");
}

fn t23() -> TestResult {
  var ok = str_err(rpc_error_message("{}"));
  if !str_err(rpc_error_message("{\"message\":7}")) { ok = false; }
  if !str_err(rpc_error_message("{\"message\":\"x}")) { ok = false; }
  return assert(ok, "rpc_error_message: missing/non-string/unterminated are Err");
}

fn t24() -> TestResult {
  let req = rpc_request(11, MIX, "[1,2]");
  var ok = int_ok_is(rpc_id(req), 11);
  if !str_ok_is(rpc_method(req), MIX) { ok = false; }
  if !streq(req, "{\"jsonrpc\":\"2.0\",\"method\":\"" + MIX_ESC + "\",\"params\":[1,2],\"id\":11}") { ok = false; }
  return assert(ok, "round-trip: escaped request method and pinned envelope");
}

fn t25() -> TestResult {
  let e = rpc_error(12, -32000, MIX, "{}");
  var ok = int_ok_is(rpc_id(e), 12);
  if !int_ok_is(rpc_error_code(e), -32000) { ok = false; }
  if !str_ok_is(rpc_error_message(e), MIX) { ok = false; }
  if !streq(e, "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32000,\"message\":\"" + MIX_ESC + "\",\"data\":{}},\"id\":12}") { ok = false; }
  let n = rpc_notification(MIX, "\"p\"");
  if !str_ok_is(rpc_method(n), MIX) { ok = false; }
  return assert(ok, "round-trip: error members and notification method");
}

fn t26() -> TestResult {
  var ok = streq(rpc_escape(""), "");
  if !streq(rpc_request(0, "", ""), "{\"jsonrpc\":\"2.0\",\"method\":\"\",\"id\":0}") { ok = false; }
  if !streq(rpc_notification("", ""), "{\"jsonrpc\":\"2.0\",\"method\":\"\"}") { ok = false; }
  if !streq(rpc_response(0, ""), "{\"jsonrpc\":\"2.0\",\"result\":null,\"id\":0}") { ok = false; }
  if !streq(rpc_error(0, 0, "", ""), "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":0,\"message\":\"\"},\"id\":0}") { ok = false; }
  if !str_ok_is(rpc_method("{\"method\":\"\"}"), "") { ok = false; }
  if !str_ok_is(rpc_error_message("{\"message\":\"\"}"), "") { ok = false; }
  return assert(ok, "empty inputs: builders and string extraction");
}

fn t27() -> TestResult {
  var ok = int_err(rpc_id("hello"));
  if !str_err(rpc_method("hello")) { ok = false; }
  if !int_err(rpc_error_code("hello")) { ok = false; }
  if !str_err(rpc_error_message("hello")) { ok = false; }
  if rpc_is_request("hello") { ok = false; }
  if rpc_is_error("hello") { ok = false; }
  return assert(ok, "malformed: scanners Err and probes are false on plain text");
}

fn main() -> Int {
  io.println("=== xiom.rpc conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.rpc: all tests passed");
  } else {
    io.println("xiom.rpc: tests failed");
  }
  return failed;
}
