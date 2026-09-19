// XIOM -- xiom.hello: the canonical minimal package
// Copyright (c) 2026 Eleftherios Notas and XIOM Foundation
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// This module is intentionally dependency-free. It is small enough to read
// in one sitting and exists to demonstrate the full package lifecycle:
// manifest -> source -> tests -> publish -> install.

module xiom.hello

// The canonical greeting text.
pub fn greeting() -> Str {
  return "Hello from xiom.hello!";
}

// Greet a person by name. Empty names fall back to greeting().
pub fn greet(name: Str) -> Str {
  if name.len() == 0 {
    return greeting();
  }
  return "Hello, " + name + "!";
}
