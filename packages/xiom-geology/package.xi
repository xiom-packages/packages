// XIOM -- xiom.geology package manifest
// Port task: populate the xiom.geology package with a real, tested, pure-XIOM
// LAS 2.0 (Log ASCII Standard) well-log text parser (sections ~V ~W ~C ~P ~A
// plus opaque ~O, fixed-point scaled values, per-cell null flags).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_geology {
  name: "xiom.geology";
  version: "0.1.2";
  description: "LAS 2.0 well-log text parsing: sections, curved-headers, wrapped/unwrapped depth-indexed data, scaled fixed-point cells and null flags";
  categories: ["science", "data"];
  keywords: ["las", "well-log", "geology", "log-ascii-standard", "parsing"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.geology"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
