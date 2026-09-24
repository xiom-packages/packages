// XIOM -- xiom.robotics package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports only xiom.math from it
// (the constant pi plus the scalar sin/cos/sqrt and abs_float helpers; no
// FFI); the tests use xiom.test, xiom.io and xiom.math from the same
// dependency.

package xiom_robotics {
  name: "xiom.robotics";
  version: "0.1.0";
  description: "Planar robot helpers: 2-link forward kinematics, reach checks, differential drive";
  categories: ["science","engineering"];
  keywords: ["robotics","kinematics","differential-drive","planar-arm"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas","The XIOM Authors"];
  modules: ["xiom.robotics"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
