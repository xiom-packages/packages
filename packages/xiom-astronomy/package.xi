// XIOM -- xiom.astronomy package manifest
// Port task: replace the xiom.astronomy placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert from it;
// the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_astronomy {
  name: "xiom.astronomy";
  version: "0.1.0";
  description: "Julian dates, days since J2000, moon phase, and zodiac helpers (integer math)";
  categories: ["science"];
  keywords: ["astronomy", "julian-date", "moon-phase", "zodiac"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.astronomy"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
