// XIOM ORBITDB -- C-ORBIT-07 second-order witness: the consumer defines an
// EXACT same-signature zero-arg `arm()` (not just a same-named 3-arg one).
// Module-local precedence must still bind mod_svc.ping()'s unqualified call
// to mod_svc's own private arm(); the consumer's identical-signature
// definition must never be reachable from inside mod_svc.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected on v0.64.4+: `svc: private arm() ran` then `done`, exit 0.
// On v0.64.3 the registration-order bare slot could win depending on module
// order (observable as `probe: consumer zero-arg arm() ran`).

module probe_shadow

use xiom.io;
use mod_svc;

fn arm() {
  io.println("probe: consumer zero-arg arm() ran (SHOULD NOT HAPPEN)");
}

fn main() -> Int {
  let rc = mod_svc.ping();
  io.println("done");
  return rc;
}
