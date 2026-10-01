// XIOM -- xiom.imaging package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// tests use xiom.test and xiom.io from it.

package xiom_imaging {
  name: "xiom.imaging";
  version: "0.1.0";
  description: "Deterministic integer grayscale image processing: 3x3 box and separable 1-2-1 Gaussian blur, Sobel magnitude, binary and Otsu threshold, nearest and integer bilinear resize, flips/rotations, histogram/percentile, integral-image box sums and alpha-free overlay copy";
  categories: ["data", "graphics"];
  keywords: ["image", "grayscale", "blur", "sobel", "resize", "otsu"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.imaging"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
