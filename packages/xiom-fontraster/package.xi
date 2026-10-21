// XIOM -- xiom.fontraster package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Carved from the engine-local package (engine packages/xiom-fontraster).
// HarfBuzz owns font parsing, cmap, composites, variations and CFF/TTF
// outlines; this package owns the pixel raster (antialiased, non-zero
// winding) and the flat XIOM ABI. The installed xiom.harfbuzz package
// supplies the linked symbols; src/fontraster.c declares only the small
// ABI surface it needs, so no HarfBuzz headers or sources are vendored.

package xiom_fontraster {
  name: "xiom.fontraster";
  version: "0.1.0";
  stage: "incubating";
  description: "Runtime antialiased glyph rasterizer for XIOM UI (HarfBuzz outlines, TTF/OTF, DPI-sized coverage bitmaps, face metrics)";
  categories: ["text", "media"];
  keywords: ["font", "glyph", "raster", "antialias", "harfbuzz", "ui"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.fontraster"];
  deps: { "xiom.harfbuzz": ">=0.1.0 <1.0.0", "xiom.std": ">=0.60.0 <1.0.0" };
}
