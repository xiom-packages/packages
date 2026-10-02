// XIOM -- xiom.image package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// tests use xiom.test and xiom.io from it.

package xiom_image {
  name: "xiom.image";
  version: "0.1.0";
  description: "Unified image pipeline: magic-byte format sniffing and metadata, packed RGBA8 pixel model with stride, RGBA/RGB/gray/BGRA conversion, and a pure proof codec subset (BMP 24/32 decode+encode, PPM P6 decode+encode)";
  categories: ["data", "graphics"];
  keywords: ["image", "decode", "encode", "bmp", "ppm", "rgba", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.image"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
