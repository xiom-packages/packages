// XIOM -- xiom.transport conformance tests (suite driver)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The declared suite for scripts/port.ps1. The checks live in six
// modules beside this file:
//   * tests/suite_frames.xi   (xiom.transport.suite_frames)   -- wire
//     codec goldens, LE primitives, truncation/garbage offsets, caps (7);
//   * tests/suite_reliable.xi (xiom.transport.suite_reliable) -- the pure
//     reliability engine over an injected clock (8);
//   * tests/suite_session.xi  (xiom.transport.suite_session)  -- lifecycle
//     handshake, channels, fragmentation, retransmit, drain (10);
//   * tests/suite_backends.xi (xiom.transport.suite_backends) -- loopback/
//     null honesty, sim determinism + tables, facade + caps (6);
//   * tests/suite_udp.xi      (xiom.transport.suite_udp)      -- real UDP
//     loopback smoke, session over UDP, typed refusals; SKIP-safe (5);
//   * tests/suite_extensions.xi (xiom.transport.suite_extensions) -- ordered
//     handler chain, rate window, additive session wrapper (6).
// Total: 42 checks. Each prints one [PASS]/[FAIL] line; the driver returns
// the failure count as the process exit code. Str equality goes through
// compare.str_compare (the recorded toolchain discipline); every fixture
// is inline and hand-composed from the declared layout.

module transport_conformance_tests

use xiom.io;
use xiom.transport.suite_frames;
use xiom.transport.suite_reliable;
use xiom.transport.suite_session;
use xiom.transport.suite_backends;
use xiom.transport.suite_udp;
use xiom.transport.suite_extensions;

pub fn main() -> Int {
  io.println("=== xiom.transport conformance tests ===");
  var failed: Int = 0;
  failed = failed + suite_frames.run_suite();
  failed = failed + suite_reliable.run_suite();
  failed = failed + suite_session.run_suite();
  failed = failed + suite_backends.run_suite();
  failed = failed + suite_udp.run_suite();
  failed = failed + suite_extensions.run_suite();
  if failed == 0 {
    io.println("xiom.transport: all tests passed");
  } else {
    io.println("xiom.transport: tests failed");
  }
  return failed;
}
