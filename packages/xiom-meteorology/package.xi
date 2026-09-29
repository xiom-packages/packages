// XIOM -- xiom.meteorology package manifest
// Port task: populate the xiom.meteorology package with real, tested,
// pure-XIOM aviation weather report codecs (METAR + TAF, decode-focused).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_meteorology {
  name: "xiom.meteorology";
  version: "0.1.1";
  description: "Aviation weather report codecs: METAR observation and TAF forecast decoding";
  categories: ["science", "data"];
  keywords: ["metar", "taf", "aviation", "weather", "decoding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.meteorology"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
