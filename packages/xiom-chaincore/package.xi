// XIOM -- xiom.chaincore package manifest
// Port task: promote the xiom.chaincore placeholder to a real, tested,
// pure-XIOM package (block headers, transaction records, chain store with
// append/validation, cumulative-work fork choice, reorg undo/redo, orphan
// pool with parent-arrival promotion and finality-depth tracking).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports only xiom.convert (decimal
// formatting for the error catalog); the tests additionally use xiom.test,
// xiom.io and xiom.string.compare. No FFI, no crypto and no external
// packages: block tags, parent tags and state roots are opaque caller-supplied
// integers.

package xiom_chaincore {
  name: "xiom.chaincore";
  version: "0.1.0";
  description: "Pure deterministic blockchain core model: block headers, transaction records, chain validation, cumulative-work fork choice, reorg undo/redo, orphan promotion and finality depth";
  categories: ["data"];
  keywords: ["blockchain", "chain", "block", "fork", "reorg", "orphan", "finality"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.chaincore"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
