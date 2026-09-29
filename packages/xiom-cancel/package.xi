// XIOM -- xiom.cancel package manifest
// Port task: replace the xiom.cancel placeholder with a real, tested,
// pure-XIOM package (cooperative cancellation tokens as a deterministic
// token tree).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing from
// it; the tests use xiom.test, xiom.io and xiom.string.compare.

package xiom_cancel {
  name: "xiom.cancel";
  version: "0.1.0";
  description: "Cooperative cancellation tokens as a deterministic token tree: subtree propagation, reason codes and logical-tick deadlines";
  categories: ["concurrency", "systems"];
  keywords: ["cancellation", "cancellation-token", "token-tree", "propagation", "deadline"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cancel"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
