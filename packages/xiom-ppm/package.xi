// XIOM -- xiom.ppm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// conformance suite uses xiom.test/xiom.io/xiom.string from it.

package xiom_ppm {
  name: "xiom.ppm";
  version: "0.1.0";
  description: "Netpbm PPM (P3/P6) parsing and building for 8-bit RGB rasters";
  categories: ["data", "graphics"];
  keywords: ["ppm", "netpbm", "image", "pixels"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ppm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
