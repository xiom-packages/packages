// XIOM ORBITDB -- env-gated fault injector for the storage shims (test-only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// M2.1 first half. Methodology borrowed from SQLite's crash VFS (kill at the
// Nth sync with random partial flushes) and redb's sync-counting crash tests
// (see docs/REFERENCE-STUDY.md).
//
// Armed entirely by environment variables; production never sets them:
//   ORBITDB_FAULT_AT    N-th mutating op to trigger (unset/<=0 = disarmed)
//   ORBITDB_FAULT_MODE  kill | partial | skip | syncfail   (default kill)
//   ORBITDB_FAULT_TAIL  partial keeps the first N bytes (default: half)
// One fire per arming; `fault_reset` re-arms (probes run several scenarios
// in one process). `kill` exits the process with code 99.
//
// Ops are split by kind: 0 = write-ish (write_at / append / truncate),
// 1 = sync. `syncfail` arms kind 1; all other modes arm kind 0.

module xiom.db.storage.fault

use xiom.io;
use xiom.os.env;
use xiom.convert.parse;

var fault_remaining: Int = -1; // -1 virgin (re-read env), >0 countdown, 0 fired
var fault_kind: Int = 0;
var fault_tail: Int = -1;

fn arm() {
  if fault_remaining >= 0 { return; }
  var n = 0;
  match parse.parse_int(env.var_or("ORBITDB_FAULT_AT", "")) {
    Ok(v) => { n = v; }
    Err(_) => { n = 0; }
  }
  if n <= 0 { return; } // stay virgin: the env may be armed later
  fault_remaining = n;
  if env.var_or("ORBITDB_FAULT_MODE", "kill") == "syncfail" {
    fault_kind = 1;
  } else {
    fault_kind = 0;
  }
  match parse.parse_int(env.var_or("ORBITDB_FAULT_TAIL", "")) {
    Ok(v) => { fault_tail = v; }
    Err(_) => { fault_tail = -1; }
  }
}

// Back to virgin so a probe can arm another scenario in the same process.
pub fn fault_reset() {
  fault_remaining = -1;
  fault_kind = 0;
  fault_tail = -1;
}

pub fn fault_armed() -> Bool {
  arm();
  return fault_remaining > 0;
}

// Gate one mutating op of `kind` (0 write-ish, 1 sync). Returns:
//   0 proceed; 1 skip (report success without doing it);
//   2 partial (write only the first `fault_partial_tail` bytes);
//   3 fail (the op returns false); 4 killed (io.exit(99) already ran).
pub fn fault_gate(kind: Int) -> Int {
  arm();
  if fault_remaining <= 0 { return 0; }
  if fault_kind != kind { return 0; }
  fault_remaining = fault_remaining - 1;
  if fault_remaining != 0 { return 0; }
  let mode = env.var_or("ORBITDB_FAULT_MODE", "kill");
  if mode == "skip" { return 1; }
  if mode == "partial" { return 2; }
  if mode == "syncfail" { return 3; }
  io.exit(99);
  return 4;
}

// Bytes a `partial` write keeps: FAULT_TAIL when set, else half.
pub fn fault_partial_tail(full: Int) -> Int {
  if fault_tail >= 0 { return fault_tail; }
  return full / 2;
}
