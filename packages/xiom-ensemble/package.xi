// XIOM -- xiom.ensemble package manifest
// Port task: promote the xiom.ensemble placeholder to a real, tested,
// pure-XIOM package (fixed-point ensemble combination on scaled integers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_ensemble {
  name: "xiom.ensemble";
  version: "0.1.1";
  description: "Fixed-point ensemble combination (scaled integers): hard/soft voting, bootstrap resampling, bagging, disagreement";
  categories: ["ai-ml", "data"];
  keywords: ["ensemble", "voting", "bagging", "bootstrap", "fixed-point", "disagreement"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ensemble"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
