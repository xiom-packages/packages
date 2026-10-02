// XIOM -- xiom.puppet package manifest
// Port task: promote the xiom.puppet placeholder to a real, tested, pure-XIOM
// package (Puppet-style declarative configuration-management model: manifest
// parsing subset, module layout/metadata, hiera lookup with interpolation,
// catalog dependency ordering, apply/change simulation and a run report).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_puppet {
  name: "xiom.puppet";
  version: "0.1.0";
  description: "Pure-XIOM Puppet-style configuration-management model: manifest parsing subset, module metadata, hiera lookup with interpolation, catalog dependency ordering, apply/change simulation and a run report";
  categories: ["systems"];
  keywords: ["puppet", "configuration-management", "manifest", "catalog", "hiera", "module"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.puppet"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
