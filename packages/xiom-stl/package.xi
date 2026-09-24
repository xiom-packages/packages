// XIOM -- xiom.stl package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module itself
// imports nothing; the tests use xiom.test/xiom.io and xiom.string helpers.

package xiom_stl {
  name: "xiom.stl";
  version: "0.1.0";
  description: "STL mesh structure: binary triangle parsing and ASCII detection (float values kept as raw bits)";
  categories: ["graphics", "data"];
  keywords: ["stl", "mesh", "3d", "binary"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.stl"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
