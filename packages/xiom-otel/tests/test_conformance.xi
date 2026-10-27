// XIOM -- xiom.otel conformance tests (suite driver)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The declared suite for scripts/port.ps1. The checks live in four modules
// beside this file:
//   * tests/suite_model.xi   (xiom.otel.suite_model)   -- hex/id helper KATs,
//     deterministic tracer, typed validators (10 checks);
//   * tests/suite_encoder.xi (xiom.otel.suite_encoder) -- exact-byte OTLP/JSON
//     goldens, canonical rules and typed error pass-through (12 checks);
//   * tests/suite_sink.xi    (xiom.otel.suite_sink)    -- sink payload
//     retention, send hook and honest counters (8 checks);
//   * tests/suite_metrics.xi (xiom.otel.suite_metrics) -- gauge construction,
//     validation, exact-byte metrics goldens and empty-batch encoding
//     (7 checks).
// Total: 37 checks. Each prints one [PASS]/[FAIL] line; the driver returns
// the failure count as the process exit code.
//
// Fixtures are inline and composed from the OTLP specification's declared
// JSON mapping (see PROVENANCE.md); no upstream implementation or generated
// file is consumed. Str equality goes through compare.str_compare.

module otel_conformance_tests

use xiom.io;
use xiom.otel.suite_model;
use xiom.otel.suite_encoder;
use xiom.otel.suite_sink;
use xiom.otel.suite_metrics;

pub fn main() -> Int {
  io.println("=== xiom.otel conformance tests ===");
  var failed: Int = 0;
  failed = failed + suite_model.run_suite();
  failed = failed + suite_encoder.run_suite();
  failed = failed + suite_sink.run_suite();
  failed = failed + suite_metrics.run_suite();
  if failed == 0 {
    io.println("xiom.otel: all tests passed");
  } else {
    io.println("xiom.otel: tests failed");
  }
  return failed;
}
