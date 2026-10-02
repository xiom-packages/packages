// XIOM -- xiom.phaser package manifest
// Port task: promote the xiom.phaser placeholder to a real, tested, pure-XIOM
// package (multi-party phaser as a deterministic state machine).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_phaser {
  name: "xiom.phaser";
  version: "0.1.0";
  description: "Multi-party phaser as a deterministic state machine (dynamic registration, phase advancement hooks, termination, tiered phasers)";
  categories: ["concurrent"];
  keywords: ["phaser", "concurrency", "synchronization", "phase", "barrier"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.phaser"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
