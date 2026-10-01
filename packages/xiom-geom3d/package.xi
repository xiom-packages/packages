// XIOM -- xiom.geom3d package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports only xiom.math (integer min/max
// for slab tests); the tests additionally use xiom.test and xiom.io from the
// same dependency. Pure XIOM integer/fixed-point math, no FFI.

package xiom_geom3d {
  name: "xiom.geom3d";
  version: "0.1.0";
  description: "Deterministic fixed-point 3D vectors, matrices, quaternions, and ray intersections";
  categories: ["graphics", "science"];
  keywords: ["3d", "geometry", "vector", "matrix", "quaternion", "ray", "fixed-point", "intersection"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.geom3d"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
