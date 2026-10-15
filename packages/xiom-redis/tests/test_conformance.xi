// XIOM -- xiom.redis conformance tests (suite driver)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The declared suite for scripts/port.ps1. The checks live in three modules
// beside this file:
//   * tests/suite_codec.xi (xiom.redis.suite_codec) -- RESP2 codec goldens,
//     decode paths, caps and typed accessors (7 checks);
//   * tests/suite_net.xi   (xiom.redis.suite_net)   -- deterministic
//     loopback-TCP client scenarios over an in-process scripted RESP
//     server (9 checks);
//   * tests/suite_live.xi  (xiom.redis.suite_live)  -- refused-connection
//     taxonomy and live tests against 127.0.0.1:6379 that print an
//     explicit SKIP line when no server is reachable (3 checks).
// Total: 19 checks. Each prints one [PASS]/[FAIL] line; the driver returns
// the failure count as the process exit code.
//
// Str equality in the suite goes through compare.str_compare (BUG 17
// discipline). No upstream implementation or generated file is consumed:
// every fixture is inline.

module redis_conformance_tests

use xiom.io;
use xiom.redis.suite_codec;
use xiom.redis.suite_net;
use xiom.redis.suite_live;

pub fn main() -> Int {
  io.println("=== xiom.redis conformance tests ===");
  var failed: Int = 0;
  failed = failed + suite_codec.run_suite();
  failed = failed + suite_net.run_suite();
  failed = failed + suite_live.run_suite();
  if failed == 0 {
    io.println("xiom.redis: all tests passed");
  } else {
    io.println("xiom.redis: tests failed");
  }
  return failed;
}
