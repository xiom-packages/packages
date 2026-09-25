// XIOM -- xiom.xbm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare; the conformance suite
// additionally uses xiom.test and xiom.io.

package xiom_xbm {
  name: "xiom.xbm";
  version: "0.1.0";
  description: "X BitMap (XBM) X11 C-source 1-bit raster parsing and canonical building";
  categories: ["graphics"];
  keywords: ["xbm", "x11", "bitmap", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.xbm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
