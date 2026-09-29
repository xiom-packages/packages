// XIOM -- xiom.countdown package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_countdown {
  name: "xiom.countdown";
  version: "0.1.0";
  description: "Pure deterministic countdown latches with one-shot and repeating expiry over integer ticks";
  categories: ["core"];
  keywords: ["countdown", "latch", "ticks", "deterministic", "expiry"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.countdown"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
