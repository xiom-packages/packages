// XIOM -- xiom.materials package manifest
// Port task: replace the xiom.materials placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing (pure integer
// fixed-point arithmetic); the tests use xiom.test and xiom.io from it.

package xiom_materials {
  name: "xiom.materials";
  version: "0.1.0";
  description: "Deterministic fixed-point isotropic material model: elastic constants, Voigt stress/strain, Hooke's law, invariants, yield checks";
  categories: ["science"];
  keywords: ["materials","elasticity","stress","strain","hooke","von-mises","yield"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.materials"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
