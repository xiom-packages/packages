// XIOM -- xiom.gedcom package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// GEDCOM 5.5.1 line codec: line grammar, nesting validation, pointers and
// CONT/CONC joining, flat parallel-vector storage and canonical emission.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_gedcom {
  name: "xiom.gedcom";
  version: "0.1.0";
  description: "GEDCOM 5.5.1 line codec: line grammar, nesting, pointers, CONT/CONC joining, canonical emission";
  categories: ["data"];
  keywords: ["gedcom", "genealogy", "parser", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.gedcom"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
