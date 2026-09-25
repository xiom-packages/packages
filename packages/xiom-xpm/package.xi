// XIOM -- xiom.xpm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder; the conformance suite additionally uses xiom.test,
// xiom.io and xiom.string.compare.

package xiom_xpm {
  name: "xiom.xpm";
  version: "0.1.0";
  description: "X PixMap (XPM) X11 color-pixmap source parsing and canonical building";
  categories: ["graphics"];
  keywords: ["xpm", "x11", "pixmap", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.xpm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
