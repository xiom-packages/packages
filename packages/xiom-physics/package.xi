// XIOM -- xiom.physics package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports only xiom.math from it
// (the constant pi and abs_float; no FFI); the tests use xiom.test, xiom.io
// and xiom.math from the same dependency.

package xiom_physics {
  name: "xiom.physics";
  version: "0.1.0";
  description: "Introductory mechanics in SI units with Float64 scalars";
  categories: ["science"];
  keywords: ["physics","mechanics","kinematics","si"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas","The XIOM Authors"];
  modules: ["xiom.physics"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
