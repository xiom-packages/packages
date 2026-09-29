// XIOM -- xiom.worker package manifest
// Port task: promote the xiom.worker placeholder to a real, tested,
// pure-XIOM package (worker-pool scheduling as a deterministic state
// machine; no FFI, no threads, no wall clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_worker {
  name: "xiom.worker";
  version: "0.1.0";
  description: "Deterministic worker-pool scheduling model: prioritized job queue, worker leases, retry backoff and fairness counters";
  categories: ["concurrency", "systems"];
  keywords: ["worker", "pool", "scheduler", "lease", "retry", "backoff", "fairness"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.worker"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
