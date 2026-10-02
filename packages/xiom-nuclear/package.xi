// XIOM -- xiom.nuclear package manifest
// Port task: replace the xiom.nuclear placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert from it
// (integer-to-decimal for nuclear notation); the tests additionally use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_nuclear {
  name: "xiom.nuclear";
  version: "0.1.0";
  description: "Deterministic integer nuclear physics: decay, fission/fusion Q-values, isotope data, cross sections, radiation dose";
  categories: ["science"];
  keywords: ["nuclear", "decay", "half-life", "radioactivity", "fission", "fusion", "isotope", "cross-section", "radiation", "dose"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nuclear"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
