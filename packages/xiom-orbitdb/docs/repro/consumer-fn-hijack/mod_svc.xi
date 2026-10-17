// XIOM ORBITDB -- C-ORBIT-07 repro bundle: service module with a module-PRIVATE
// zero-arg `arm()` that its public `ping()` calls unqualified.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module mod_svc

use xiom.io;

fn arm() {
  io.println("svc: private arm() ran");
}

pub fn ping() -> Int {
  arm();
  return 0;
}
