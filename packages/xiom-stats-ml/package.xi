// XIOM -- xiom.stats-ml package manifest
// Port task: promote the xiom.stats-ml placeholder to a real, tested,
// pure-XIOM package (fixed-point ML evaluation metrics on scaled integers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_stats_ml {
  name: "xiom.stats-ml";
  version: "0.1.0";
  description: "Fixed-point ML evaluation metrics on integers: confusion matrix, precision/recall/F1, kappa, ROC/AUC, calibration bins, class balance";
  categories: ["ai-ml", "data"];
  keywords: ["metrics", "confusion-matrix", "precision", "recall", "f1", "roc", "auc", "calibration", "kappa", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.stats-ml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
