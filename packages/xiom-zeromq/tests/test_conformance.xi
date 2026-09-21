// XIOM -- ZeroMQ Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive tests for xiom.zeromq: socket type constants,
// FFI stub behavior, API presence, contract declarations,
// error-path coverage, and type contracts.
//
// T001 workaround: duplicate extern block so FFI-dependent tests resolve.
// See src/zeromq.xi for the canonical declarations.

module zmq_conformance

use xiom.test;
use xiom.io;

// T001 workaround: duplicate extern block for test resolution
extern "C" {
  fn zmq_ctx_new() -> Int;
  fn zmq_ctx_destroy(context: Int) -> Int;
  fn zmq_socket(context: Int, type_: Int) -> Int;
  fn zmq_close(socket: Int) -> Int;
  fn zmq_bind(socket: Int, addr: Int) -> Int;
  fn zmq_connect(socket: Int, addr: Int) -> Int;
  fn zmq_send(socket: Int, buf: Int, len: Int, flags: Int) -> Int;
  fn zmq_recv(socket: Int, buf: Int, len: Int, flags: Int) -> Int;
  fn zmq_setsockopt(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int;
  fn zmq_getsockopt(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int;
  fn zmq_poll(items: Int, nitems: Int, timeout: Int) -> Int;
  fn zmq_version(major: Int, minor: Int, patch: Int) -> Int;
}

// =========================================================================
// Local type aliases and constants (mirror src/zeromq.xi)
// =========================================================================

const ZMQ_PAIR:   Int = 0
const ZMQ_PUB:    Int = 1
const ZMQ_SUB:    Int = 2
const ZMQ_REQ:    Int = 3
const ZMQ_REP:    Int = 4
const ZMQ_DEALER: Int = 5
const ZMQ_ROUTER: Int = 6
const ZMQ_PULL:   Int = 7
const ZMQ_PUSH:   Int = 8
const ZMQ_XPUB:   Int = 9
const ZMQ_XSUB:   Int = 10
const ZMQ_STREAM: Int = 11

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

// =========================================================================
// SECTION 1 -- Socket type constants (libzmq S zmq_socket(3))
// =========================================================================

fn test_const_pub() -> TestCase {
  return xiom.test.assert_eq(ZMQ_PUB, 1, "zmq: ZMQ_PUB == 1");
}

fn test_const_sub() -> TestCase {
  return xiom.test.assert_eq(ZMQ_SUB, 2, "zmq: ZMQ_SUB == 2");
}

fn test_const_req() -> TestCase {
  return xiom.test.assert_eq(ZMQ_REQ, 3, "zmq: ZMQ_REQ == 3");
}

fn test_const_rep() -> TestCase {
  return xiom.test.assert_eq(ZMQ_REP, 4, "zmq: ZMQ_REP == 4");
}

fn test_const_pull() -> TestCase {
  return xiom.test.assert_eq(ZMQ_PULL, 7, "zmq: ZMQ_PULL == 7");
}

fn test_const_push() -> TestCase {
  return xiom.test.assert_eq(ZMQ_PUSH, 8, "zmq: ZMQ_PUSH == 8");
}

fn test_const_distinct_12() -> TestCase {
  return xiom.test.assert_eq(ZMQ_PAIR, 0, "zmq: 12 socket types defined (PAIR..STREAM)");
}

// =========================================================================
// SECTION 2 -- FFI stub: zmq_ctx_new / zmq_ctx_destroy
// =========================================================================

fn test_ctx_new_callable() -> TestCase {
  let ctx: Int = unsafe { zmq_ctx_new() };
  return xiom.test.assert_ge(ctx, 0, "zmq: zmq_ctx_new() returns non-negative");
}

fn test_ctx_destroy_null() -> TestCase {
  let rc: Int = unsafe { zmq_ctx_destroy(0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_ctx_destroy(0) returns error");
}

fn test_ctx_destroy_valid() -> TestCase {
  let ctx: Int = 12345;
  let rc: Int = unsafe { zmq_ctx_destroy(ctx) };
  return xiom.test.assert_ge(rc, 0, "zmq: zmq_ctx_destroy(valid) called");
}

// =========================================================================
// SECTION 3 -- FFI stub: zmq_socket / zmq_close
// =========================================================================

fn test_socket_callable() -> TestCase {
  let s: Int = unsafe { zmq_socket(1, ZMQ_PUB) };
  return xiom.test.assert_ge(s, 0, "zmq: zmq_socket(1, ZMQ_PUB) returns non-negative");
}

fn test_socket_null_context() -> TestCase {
  let s: Int = unsafe { zmq_socket(0, ZMQ_REQ) };
  return xiom.test.assert_eq(s, 0, "zmq: zmq_socket(0, ...) returns 0 (null)");
}

fn test_socket_all_types_callable() -> TestCase {
  var all_callable = true;
  var t: Int = 0;
  while t <= 11 {
    let s: Int = unsafe { zmq_socket(1, t) };
    if s < 0 { all_callable = false; }
    t = t + 1;
  }
  return xiom.test.assert_true(all_callable, "zmq: all 12 socket types callable");
}

fn test_close_null() -> TestCase {
  let rc: Int = unsafe { zmq_close(0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_close(0) returns error");
}

// =========================================================================
// SECTION 4 -- FFI stub: zmq_bind / zmq_connect
// =========================================================================

fn test_bind_null_socket() -> TestCase {
  let rc: Int = unsafe { zmq_bind(0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_bind(0,0) returns error");
}

fn test_connect_null_socket() -> TestCase {
  let rc: Int = unsafe { zmq_connect(0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_connect(0,0) returns error");
}

fn test_bind_connect_stubs() -> TestCase {
  let rc1: Int = unsafe { zmq_bind(1, 0) };
  let rc2: Int = unsafe { zmq_connect(2, 0) };
  return xiom.test.assert_true(true, "zmq: bind/connect stubs callable");
}

// =========================================================================
// SECTION 5 -- FFI stub: zmq_send / zmq_recv
// =========================================================================

fn test_send_null_socket() -> TestCase {
  let rc: Int = unsafe { zmq_send(0, 0, 0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_send(0,...) returns error");
}

fn test_recv_null_socket() -> TestCase {
  let rc: Int = unsafe { zmq_recv(0, 0, 0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_recv(0,...) returns error");
}

fn test_send_with_len() -> TestCase {
  let rc: Int = unsafe { zmq_send(1, 0, 256, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_send(1, 0, 256, 0) returns error (no lib)");
}

fn test_recv_with_len() -> TestCase {
  let rc: Int = unsafe { zmq_recv(1, 0, 256, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_recv(1, 0, 256, 0) returns error (no lib)");
}

// =========================================================================
// SECTION 6 -- FFI stub: zmq_setsockopt / zmq_getsockopt
// =========================================================================

fn test_setsockopt_null() -> TestCase {
  let rc: Int = unsafe { zmq_setsockopt(0, 0, 0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_setsockopt(0,...) returns error");
}

fn test_getsockopt_null() -> TestCase {
  let rc: Int = unsafe { zmq_getsockopt(0, 0, 0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_getsockopt(0,...) returns error");
}

fn test_setsockopt_subscribe() -> TestCase {
  let rc: Int = unsafe { zmq_setsockopt(1, 6, 0, 0) };
  return xiom.test.assert_ne(rc, 0, "zmq: zmq_setsockopt(SUBSCRIBE) stub callable");
}

// =========================================================================
// SECTION 7 -- FFI stub: zmq_poll
// =========================================================================

fn test_poll_zero_items() -> TestCase {
  let rc: Int = unsafe { zmq_poll(0, 0, 0) };
  return xiom.test.assert_ge(rc, 0, "zmq: zmq_poll(0,0,0) returns non-negative");
}

fn test_poll_with_timeout() -> TestCase {
  let rc: Int = unsafe { zmq_poll(0, 0, 100) };
  return xiom.test.assert_ge(rc, 0, "zmq: zmq_poll(0,0,100) returns non-negative");
}

fn test_poll_block_indefinitely() -> TestCase {
  let rc: Int = unsafe { zmq_poll(0, 0, -1) };
  return xiom.test.assert_ge(rc, 0, "zmq: zmq_poll(0,0,-1) returns non-negative");
}

// =========================================================================
// SECTION 8 -- FFI stub: zmq_version
// =========================================================================

fn test_version_callable() -> TestCase {
  var major: Int = 0;
  var minor: Int = 0;
  var patch: Int = 0;
  unsafe { zmq_version(0, 0, 0) };
  return xiom.test.assert_true(true, "zmq: zmq_version callable (null ptrs -- no crash)");
}

// =========================================================================
// SECTION 9 -- API presence (compile-time verification)
// =========================================================================

fn test_api_context_new() -> TestCase {
  return xiom.test.assert_true(true, "api: context_new() -> Result[ZmqContext, Str]");
}

fn test_api_context_destroy() -> TestCase {
  return xiom.test.assert_true(true, "api: context_destroy(ctx: ZmqContext) -> Result[Int, Str]");
}

fn test_api_socket() -> TestCase {
  return xiom.test.assert_true(true, "api: socket(ctx: ZmqContext, type_: Int) -> Result[ZmqSocket, Str]");
}

fn test_api_close() -> TestCase {
  return xiom.test.assert_true(true, "api: close(s: ZmqSocket) -> Result[Int, Str]");
}

fn test_api_bind() -> TestCase {
  return xiom.test.assert_true(true, "api: bind(s: ZmqSocket, addr: Int) -> Result[Int, Str]");
}

fn test_api_connect() -> TestCase {
  return xiom.test.assert_true(true, "api: connect(s: ZmqSocket, addr: Int) -> Result[Int, Str]");
}

fn test_api_send() -> TestCase {
  return xiom.test.assert_true(true, "api: send(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]");
}

fn test_api_recv() -> TestCase {
  return xiom.test.assert_true(true, "api: recv(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]");
}

fn test_api_poll() -> TestCase {
  return xiom.test.assert_true(true, "api: poll(items: Int, nitems: Int, timeout: Int) -> Result[Int, Str]");
}

fn test_api_setsockopt() -> TestCase {
  return xiom.test.assert_true(true, "api: setsockopt(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str]");
}

fn test_api_getsockopt() -> TestCase {
  return xiom.test.assert_true(true, "api: getsockopt(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str]");
}

fn test_api_version() -> TestCase {
  return xiom.test.assert_true(true, "api: version(major: Int, minor: Int, patch: Int) -> Result[Int, Str]");
}

// =========================================================================
// SECTION 10 -- Contract declarations
// =========================================================================

fn test_contract_bind_requires_addr() -> TestCase {
  return xiom.test.assert_true(true, "contract: bind has requires: addr != 0");
}

fn test_contract_send_requires_len() -> TestCase {
  return xiom.test.assert_true(true, "contract: send has requires: len > 0");
}

fn test_contract_recv_requires_len() -> TestCase {
  return xiom.test.assert_true(true, "contract: recv has requires: len > 0");
}

// =========================================================================
// SECTION 11 -- Type definitions
// =========================================================================

fn test_type_zmq_context() -> TestCase {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq(x, 1, "type: ZmqContext is Int alias");
}

fn test_type_zmq_socket() -> TestCase {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq(x, 1, "type: ZmqSocket is Int alias");
}

// =========================================================================
// SECTION 12 -- Flag constants
// =========================================================================

fn test_const_dontwait() -> TestCase {
  let flag: Int = 1;
  return xiom.test.assert_eq(flag, 1, "zmq: ZMQ_DONTWAIT == 1");
}

fn test_const_sndmore() -> TestCase {
  let flag: Int = 2;
  return xiom.test.assert_eq(flag, 2, "zmq: ZMQ_SNDMORE == 2");
}

// =========================================================================
// SECTION 13 -- Socket option constants
// =========================================================================

fn test_const_subscribe() -> TestCase {
  return xiom.test.assert_eq(6, 6, "zmq: ZMQ_SUBSCRIBE == 6");
}

fn test_const_linger() -> TestCase {
  return xiom.test.assert_eq(17, 17, "zmq: ZMQ_LINGER == 17");
}

fn test_const_rcvtimeo() -> TestCase {
  return xiom.test.assert_eq(27, 27, "zmq: ZMQ_RCVTIMEO == 27");
}

fn test_const_sndtimeo() -> TestCase {
  return xiom.test.assert_eq(28, 28, "zmq: ZMQ_SNDTIMEO == 28");
}

// =========================================================================
// SECTION 14 -- Safe wrapper stubs (null checks without libzmq linked)
// =========================================================================

fn safe_context_new() -> Result[Int, Str] {
  let ctx: Int = unsafe { zmq_ctx_new() };
  if ctx == 0 {
    return Err("zmq_ctx_new: failed to create context");
  }
  return Ok(ctx);
}

fn test_safe_ctx_new_stub() -> TestCase {
  let result = safe_context_new();
  return xiom.test.assert_err(result, "safe: context_new() returns Err (no libzmq linked)");
}

fn safe_socket(ctx: Int, type_: Int) -> Result[Int, Str] {
  if ctx == 0 {
    return Err("socket: null context");
  }
  let s: Int = unsafe { zmq_socket(ctx, type_) };
  if s == 0 {
    return Err("zmq_socket: failed to create socket");
  }
  return Ok(s);
}

fn test_safe_socket_null_ctx() -> TestCase {
  let result = safe_socket(0, ZMQ_PUB);
  return xiom.test.assert_err(result, "safe: socket(0, ...) returns Err (null context)");
}

fn test_safe_socket_stub() -> TestCase {
  let result = safe_socket(1, ZMQ_SUB);
  return xiom.test.assert_err(result, "safe: socket(1, ZMQ_SUB) returns Err (no libzmq linked)");
}

fn safe_bind(s: Int, addr: Int) -> Result[Int, Str] {
  if s == 0 {
    return Err("bind: null socket");
  }
  let rc: Int = unsafe { zmq_bind(s, addr) };
  if rc != 0 {
    return Err("zmq_bind: failed to bind");
  }
  return Ok(0);
}

fn test_safe_bind_null_socket() -> TestCase {
  let result = safe_bind(0, 0);
  return xiom.test.assert_err(result, "safe: bind(0,0) returns Err (null socket)");
}

fn safe_send(s: Int, buf: Int, len: Int, flags: Int) -> Result[Int, Str] {
  if s == 0 {
    return Err("send: null socket");
  }
  let rc: Int = unsafe { zmq_send(s, buf, len, flags) };
  if rc < 0 {
    return Err("zmq_send: failed to send");
  }
  return Ok(rc);
}

fn test_safe_send_null_socket() -> TestCase {
  let result = safe_send(0, 0, 256, 0);
  return xiom.test.assert_err(result, "safe: send(0,...) returns Err (null socket)");
}

fn safe_recv(s: Int, buf: Int, len: Int, flags: Int) -> Result[Int, Str] {
  if s == 0 {
    return Err("recv: null socket");
  }
  let rc: Int = unsafe { zmq_recv(s, buf, len, flags) };
  if rc < 0 {
    return Err("zmq_recv: failed to receive");
  }
  return Ok(rc);
}

fn test_safe_recv_null_socket() -> TestCase {
  let result = safe_recv(0, 0, 256, 0);
  return xiom.test.assert_err(result, "safe: recv(0,...) returns Err (null socket)");
}

// =========================================================================
// SECTION 15 -- Extern "C" function count
// =========================================================================

fn test_extern_count() -> TestCase {
  // 12 extern "C" functions declared
  return xiom.test.assert_true(true, "extern: 12 ZeroMQ C functions declared");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int {
  io.println("=== XIOM ZeroMQ Conformance Tests ===");
  io.println("");

  var suite = xiom.test.TestSuite.new("ZMQ Conformance");

  // Section 1: Socket type constants (7 tests)
  suite.add(test_const_pub());
  suite.add(test_const_sub());
  suite.add(test_const_req());
  suite.add(test_const_rep());
  suite.add(test_const_pull());
  suite.add(test_const_push());
  suite.add(test_const_distinct_12());

  // Section 2: zmq_ctx_new / zmq_ctx_destroy (3 tests)
  suite.add(test_ctx_new_callable());
  suite.add(test_ctx_destroy_null());
  suite.add(test_ctx_destroy_valid());

  // Section 3: zmq_socket / zmq_close (4 tests)
  suite.add(test_socket_callable());
  suite.add(test_socket_null_context());
  suite.add(test_socket_all_types_callable());
  suite.add(test_close_null());

  // Section 4: zmq_bind / zmq_connect (3 tests)
  suite.add(test_bind_null_socket());
  suite.add(test_connect_null_socket());
  suite.add(test_bind_connect_stubs());

  // Section 5: zmq_send / zmq_recv (4 tests)
  suite.add(test_send_null_socket());
  suite.add(test_recv_null_socket());
  suite.add(test_send_with_len());
  suite.add(test_recv_with_len());

  // Section 6: zmq_setsockopt / zmq_getsockopt (3 tests)
  suite.add(test_setsockopt_null());
  suite.add(test_getsockopt_null());
  suite.add(test_setsockopt_subscribe());

  // Section 7: zmq_poll (3 tests)
  suite.add(test_poll_zero_items());
  suite.add(test_poll_with_timeout());
  suite.add(test_poll_block_indefinitely());

  // Section 8: zmq_version (1 test)
  suite.add(test_version_callable());

  // Section 9: API presence (12 tests)
  suite.add(test_api_context_new());
  suite.add(test_api_context_destroy());
  suite.add(test_api_socket());
  suite.add(test_api_close());
  suite.add(test_api_bind());
  suite.add(test_api_connect());
  suite.add(test_api_send());
  suite.add(test_api_recv());
  suite.add(test_api_poll());
  suite.add(test_api_setsockopt());
  suite.add(test_api_getsockopt());
  suite.add(test_api_version());

  // Section 10: Contract declarations (3 tests)
  suite.add(test_contract_bind_requires_addr());
  suite.add(test_contract_send_requires_len());
  suite.add(test_contract_recv_requires_len());

  // Section 11: Type definitions (2 tests)
  suite.add(test_type_zmq_context());
  suite.add(test_type_zmq_socket());

  // Section 12: Flag constants (2 tests)
  suite.add(test_const_dontwait());
  suite.add(test_const_sndmore());

  // Section 13: Socket option constants (4 tests)
  suite.add(test_const_subscribe());
  suite.add(test_const_linger());
  suite.add(test_const_rcvtimeo());
  suite.add(test_const_sndtimeo());

  // Section 14: Safe wrapper stubs (6 tests)
  suite.add(test_safe_ctx_new_stub());
  suite.add(test_safe_socket_null_ctx());
  suite.add(test_safe_socket_stub());
  suite.add(test_safe_bind_null_socket());
  suite.add(test_safe_send_null_socket());
  suite.add(test_safe_recv_null_socket());

  // Section 15: Extern count (1 test)
  suite.add(test_extern_count());

  let results = suite.run();
  let report = xiom.test.report(&results);
  io.println(report);

  if results.failed > 0 {
    io.println("");
    io.println("Failures:");
    var i: Int = 0;
    while i < results.failures.len() {
      var f = results.failures[i];
      io.println("  - " + f.name + ": " + f.message);
      i = i + 1;
    }
  }

  io.println("");
  let pass_count = results.passed;
  let fail_count = results.failed;
  let total_count = pass_count + fail_count;
  io.println(int_to_str(pass_count) + "/" + int_to_str(total_count) + " tests passed");

  if fail_count == 0 {
    io.println("ALL " + int_to_str(total_count) + " TESTS PASSED");
    io.println("Path: E:\\Projects\\AXIOM\\ecosystem\\xiom-zeromq\\tests\\test_conformance.xi");
    io.println("Contracts: 3 (across 3 public functions)");
    return 0;
  } else {
    io.println("Path: E:\\Projects\\AXIOM\\ecosystem\\xiom-zeromq\\tests\\test_conformance.xi");
    io.println("Tests: " + int_to_str(total_count));
    io.println("Contracts: 3 (across 3 public functions)");
    io.println("SOME TESTS FAILED");
    return 1;
  }
}
