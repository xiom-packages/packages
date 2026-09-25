// XIOM -- xiom.dimacs package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_dimacs {
  name: "xiom.dimacs";
  version: "0.1.0";
  description: "DIMACS CNF parsing and canonical emission with strict validation";
  categories: ["safety"];
  keywords: ["dimacs", "cnf", "sat", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dimacs"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
