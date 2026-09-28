// XIOM -- xiom.lockfree package manifest
// Port task: promote the xiom.lockfree placeholder to a real, tested,
// pure-XIOM package (deterministic atomic-step models of lock-free
// structures: Treiber stack, bounded MPMC ring queue, atomic counters).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it (plus xiom.convert.int for int_to_base); the tests additionally use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_lockfree {
  name: "xiom.lockfree";
  version: "0.1.0";
  description: "Deterministic single-threaded models of lock-free structures: Treiber stack with ABA tags, bounded MPMC ring queue, atomic counters";
  categories: ["concurrency", "data"];
  keywords: ["lockfree", "concurrency", "atomic", "cas", "aba", "treiber", "mpmc", "ring-buffer"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.lockfree"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
