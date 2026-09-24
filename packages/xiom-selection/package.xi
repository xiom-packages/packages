// XIOM -- xiom.selection package manifest
// Port task: promote the xiom.selection placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing (Int/Vec[Int]
// only); the tests additionally use xiom.test, xiom.io and xiom.core.

package xiom_selection {
  name: "xiom.selection";
  version: "0.1.0";
  description: "Deterministic selection operators for evolutionary loops: roulette, tournament, elite, rank weights";
  categories: ["science","tooling"];
  keywords: ["selection","evolutionary","roulette","tournament"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.selection"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
