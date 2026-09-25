// XIOM -- xiom.gcode package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.convert from it; the tests additionally use xiom.test, xiom.io,
// xiom.math and xiom.string.compare.

package xiom_gcode {
  name: "xiom.gcode";
  version: "0.1.0";
  description: "G-code parsing and canonical emission for a documented line subset";
  categories: ["graphics"];
  keywords: ["gcode", "cnc", "machining", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.gcode"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
