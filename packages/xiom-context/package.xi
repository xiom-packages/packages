// XIOM -- xiom.context package manifest
// Port task: replace the xiom.context placeholder with a real, tested,
// pure-XIOM package (immutable context propagation as a deterministic
// parent chain -- no FFI, no threads, no wall clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_context {
  name: "xiom.context";
  version: "0.1.0";
  description: "Immutable context propagation as a deterministic parent chain: shadowing lookups, inherited logical-tick deadlines, cancellation reason codes and key-value flattening";
  categories: ["concurrency", "systems"];
  keywords: ["context", "propagation", "immutable", "parent-chain", "deadline", "cancellation", "shadowing"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.context"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
