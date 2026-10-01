// XIOM -- xiom.chromatography package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports only
// xiom.string, xiom.string.compare and xiom.convert; the tests use xiom.io
// and xiom.test from the same dependency.

package xiom_chromatography {
  name: "xiom.chromatography";
  version: "0.1.0";
  description: "Deterministic fixed-point chromatography data model: peak tables, resolution, Kovats indices, QC flags and a canonical text codec";
  categories: ["science"];
  keywords: ["chromatography","peaks","retention","resolution","kovats","qc","codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas","The XIOM Authors"];
  modules: ["xiom.chromatography"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
