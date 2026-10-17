// XIOM ORBITDB -- C-ORBIT-07 repro: the consumer module defines its own
// 3-arg `arm(Str,Str,Str)` and calls mod_svc.ping(), whose internal call to
// its PRIVATE zero-arg arm() must run the service's own function.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected: `svc: private arm() ran` then `done`.
// Observed on v0.64.3: the consumer's arm is reached instead (no diagnostic).

module probe_hijack

use xiom.io;
use mod_svc;

fn arm(a: Str, b: Str, c: Str) {
  io.println("probe: consumer arm(a=[" + a + "] b=[" + b + "] c=[" + c + "])");
}

fn main() -> Int {
  let rc = mod_svc.ping();
  io.println("done");
  return rc;
}
