// XIOM -- xiom.svm package manifest
// Port task: promote the xiom.svm placeholder to a real, tested, pure-XIOM
// package (deterministic fixed-point linear SVM on scaled integers: no
// floats, no FFI, no Vec[Float64], no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it (decimal
// rendering for the model dump); the tests additionally use xiom.test,
// xiom.io, xiom.string and xiom.string.compare.

package xiom_svm {
  name: "xiom.svm";
  version: "0.1.0";
  description: "Deterministic fixed-point linear SVM over scaled integers: hinge-loss sub-gradient training with seeded LCG shuffling, decaying learning rate, decision scores, margin band support-vector counting, accuracy, text model dump";
  categories: ["ai-ml", "data"];
  keywords: ["svm", "linear-svm", "hinge-loss", "fixed-point", "classification", "margin", "support-vector", "subgradient"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.svm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
