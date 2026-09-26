// XIOM -- xiom.pcf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM X11 PCF bitmap-font codec subset (no FFI).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests
// use xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex from it.

package xiom_pcf {
  name: "xiom.pcf";
  version: "0.1.0";
  description: "Pure-XIOM X11 PCF bitmap-font codec subset: headers, tables, metrics, bitmaps and encodings";
  categories: ["graphics"];
  keywords: ["pcf", "x11", "font", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pcf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
