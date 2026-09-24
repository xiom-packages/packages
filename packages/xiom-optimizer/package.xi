// XIOM -- xiom.optimizer package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports nothing; the tests use xiom.test and
// xiom.io from it.

package xiom_optimizer {
  name: "xiom.optimizer";
  version: "0.1.0";
  description: "Deterministic single-variable optimizers: hill climb, grid search, simulated annealing";
  categories: ["science","tooling"];
  keywords: ["optimizer","hill-climb","annealing","search"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.optimizer"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
