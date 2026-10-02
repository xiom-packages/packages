// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.climate package manifest
// Port task: replace the xiom.climate placeholder with a real, tested,
// pure-XIOM package (no FFI, integer/fixed-point math only).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_climate {
  name: "xiom.climate";
  version: "0.1.0";
  description: "Integer fixed-point climate helpers: energy-balance simulation, paleoclimate proxies, emission scenarios, climate zones, and trend analysis";
  categories: ["science"];
  keywords: ["climate", "energy-balance", "paleoclimate", "scenarios", "climate-zones", "trends"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.climate"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
