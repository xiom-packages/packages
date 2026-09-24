// XIOM -- xiom.weather package manifest
// Port task: promote the xiom.weather placeholder to a real, tested,
// pure-XIOM package (METAR observation decoding).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_weather {
  name: "xiom.weather";
  version: "0.1.0";
  description: "METAR observation decoding: wind, visibility, temperature, altimeter, flight category";
  categories: ["science", "data"];
  keywords: ["metar", "weather", "aviation", "decoding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.weather"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
