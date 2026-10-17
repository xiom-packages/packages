// XIOM ORBITDB -- C-ORBIT-07 control: same program WITHOUT a consumer-defined
// `arm`, so mod_svc.ping() must run the service's own private arm().
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected (v0.64.3): `svc: private arm() ran` then `done`.

module probe_clean

use xiom.io;
use mod_svc;

fn main() -> Int {
  let rc = mod_svc.ping();
  io.println("done");
  return rc;
}
