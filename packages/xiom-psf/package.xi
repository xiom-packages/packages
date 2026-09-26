// XIOM -- xiom.psf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield pure-XIOM PSF1/PSF2 console-font codec (no FFI).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests
// use xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_psf {
  name: "xiom.psf";
  version: "0.1.0";
  description: "Pure-XIOM PSF1/PSF2 console-font codec for glyph bytes and unicode tables";
  categories: ["graphics"];
  keywords: ["psf", "console", "font", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.psf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
