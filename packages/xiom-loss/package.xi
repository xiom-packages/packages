// XIOM -- xiom.loss package manifest
// Port task: promote the xiom.loss placeholder to a real, tested, pure-XIOM
// package (fixed-point supervised loss functions on scaled integers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and xiom.string.

package xiom_loss {
  name: "xiom.loss";
  version: "0.1.0";
  description: "Fixed-point supervised loss functions (scaled integers): MSE, MAE, hinge, binary and categorical cross-entropy";
  categories: ["ai-ml", "science"];
  keywords: ["loss", "mse", "mae", "hinge", "cross-entropy", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.loss"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
