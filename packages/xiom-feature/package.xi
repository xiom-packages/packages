// XIOM -- xiom.feature package manifest
// Port task: promote the xiom.feature placeholder to a real, tested,
// pure-XIOM package (feature engineering on scaled integers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and xiom.string.

package xiom_feature {
  name: "xiom.feature";
  version: "0.1.1";
  description: "Feature engineering on scaled integers: polynomial expansion, feature hashing, extraction, scaling, selection";
  categories: ["ai-ml", "data"];
  keywords: ["feature-engineering", "polynomial", "feature-hashing", "scaling", "selection"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.feature"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
