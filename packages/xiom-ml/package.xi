// XIOM -- xiom.ml package manifest
// Port task: promote the xiom.ml placeholder to a real, tested, pure-XIOM
// package (fixed-point statistical and Bayesian ML primitives).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// tests use xiom.test, xiom.io and xiom.string.compare from it.

package xiom_ml {
  name: "xiom.ml";
  version: "0.1.0";
  description: "Fixed-point statistical and Bayesian ML: linear/ridge regression, Metropolis-Hastings MCMC, Beta-Binomial conjugate inference and 1-D Kalman filtering on scaled integers";
  categories: ["ai-ml", "data"];
  keywords: ["regression", "ridge", "mcmc", "metropolis-hastings", "bayesian", "beta-binomial", "credible-interval", "kalman", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
