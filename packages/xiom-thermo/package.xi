// XIOM -- xiom.thermo package manifest
// Port task: replace the xiom.thermo placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing (pure integer
// arithmetic); the tests use xiom.test and xiom.io from it.

package xiom_thermo {
  name: "xiom.thermo";
  version: "0.1.0";
  description: "Exact integer unit conversions for temperature, pressure, energy, and speed";
  categories: ["science","engineering"];
  keywords: ["units","temperature","pressure","conversion"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.thermo"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
