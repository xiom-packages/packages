// XIOM -- xiom.boosting package manifest
// Port task: promote the xiom.boosting placeholder to a real, tested,
// pure-XIOM package (deterministic fixed-point gradient boosting over
// integer data; no floats, no FFI, no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it (decimal
// rendering for the model dump); the tests additionally use xiom.test,
// xiom.io, xiom.string and xiom.string.compare.

package xiom_boosting {
  name: "xiom.boosting";
  version: "0.1.0";
  description: "Deterministic fixed-point gradient boosting over integer data: depth-1/2 regression stumps, residual updates, basis-point learning rate, seeded row/feature subsampling, staged loss, feature importance, text dump";
  categories: ["ai-ml", "data"];
  keywords: ["gradient-boosting", "gbdt", "regression", "fixed-point", "stumps", "residual", "feature-importance"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.boosting"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
