// XIOM -- xiom.mechanics package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing (pure
// fixed-point integer arithmetic); the tests use xiom.test, xiom.io and
// xiom.string.compare from the same dependency.

package xiom_mechanics {
  name: "xiom.mechanics";
  version: "0.1.0";
  description: "Deterministic fixed-point classical mechanics: semi-implicit integration, collisions, spring-damper";
  categories: ["science"];
  keywords: ["mechanics","dynamics","kinematics","collisions","fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mechanics"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
