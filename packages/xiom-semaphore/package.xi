// XIOM -- xiom.semaphore package manifest
// Port task: promote the xiom.semaphore placeholder to a real, tested,
// pure-XIOM package (counting semaphore as a deterministic state machine).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_semaphore {
  name: "xiom.semaphore";
  version: "0.1.0";
  description: "Counting semaphore as a deterministic state machine (permits, FIFO waiters, fairness trace)";
  categories: ["core", "tooling"];
  keywords: ["semaphore", "concurrency", "permits", "fifo", "waiters"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.semaphore"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
