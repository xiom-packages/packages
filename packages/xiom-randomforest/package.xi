// XIOM -- xiom.randomforest package manifest
// Port task: promote the xiom.randomforest placeholder to a real, tested,
// pure-XIOM package (deterministic CART-style decision-tree ensemble over
// integer features and labels; no floats, no FFI, no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it (decimal
// rendering for the tree dump); the tests additionally use xiom.test, xiom.io,
// xiom.string and xiom.string.compare.

package xiom_randomforest {
  name: "xiom.randomforest";
  version: "0.1.0";
  description: "Deterministic CART-style random forest over integer features and labels: Gini split search, seeded bootstrap, forest voting, feature importance, text dump";
  categories: ["ai-ml", "data"];
  keywords: ["random-forest", "decision-tree", "cart", "gini", "bootstrap", "ensemble", "classification", "feature-importance"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.randomforest"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
